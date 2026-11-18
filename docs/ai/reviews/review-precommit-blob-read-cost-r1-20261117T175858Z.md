# Code review — precommit-blob-read-cost — r1

security_relevant: true

```yaml
review:
  scope: "git diff 03f3e6df -- .aai/scripts/pre-commit-checks.sh tests/skills/test-aai-pre-commit-checks.sh CHANGELOG.md (+ untracked docs/issues/DEBT-0016-precommit-blob-read-cost.md, docs/specs/SPEC-0301-spec-precommit-blob-read-cost.md); ledgers docs/ai/EVENTS.jsonl, docs/ai/decisions.jsonl checked append-only"
  spec: docs/specs/SPEC-0301-spec-precommit-blob-read-cost.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "pre-commit-checks.sh:105-106,150; TEST-3871 green (r1 suite run)" }
      - { ac: Spec-AC-02, call: compliant, citation: "pre-commit-checks.sh:150,174-175; TEST-3872 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "pre-commit-checks.sh:157,176-178,182; TEST-3873 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "pre-commit-checks.sh:105,113-144,159-160; TEST-3874 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "pre-commit-checks.sh:102-103,164-172; TEST-3875 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3876 green (cmp against git show 03f3e6df script; non-git and cwd-in-.git rows)" }
      - { ac: Spec-AC-07, call: compliant, citation: "test-aai-pre-commit-checks.sh rc 0, test-aai-docs-audit.sh rc 0, check-cd-subshell-leak rc 0 (this review); TEST-3877" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33-35; TEST-3878 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-3879 green (installed hook, partial commit, 40-file commit)" }
      - { ac: Spec-AC-10, call: compliant, citation: "pre-commit-checks.sh:111-148,183-190,204-206,273-274; TEST-3880/3881/3882 green; mutation evidence for TEST-3880 mis-referenced, see NB-0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0301-spec-precommit-blob-read-cost.md, line: 361,
          issue: "NB-0: TEST-3880 Mutation cell names mut-3880-fdsave.patch; the record carries the canonical mutation-TEST-3880.patch (byte-identical). mutation-gate.mjs exit 5",
          failure_scenario: "/aai-pr runs close-work-item.mjs, which runs mutation-gate.mjs for the spec; it refuses the close. Repro: review-precommit-blob-read-cost-r1-mutation-gate.out" }
      - { rank: NON-BLOCKING, file: .aai/scripts/pre-commit-checks.sh, line: 162,
          issue: "NB-1: a size of a leading zero and an 8 or 9 (028) passes the digit test at :160, then $((size / 1048576)) raises an arithmetic error. Non-interactive bash drops the whole top-level if-block at :108-191 (set -e does not fire), so the copy loop and all three D13 count checks are skipped",
          failure_scenario: "a git (or PATH wrapper) that zero-pads a header size: a staged api_key line exits 0 with PASS WITH WARNINGS. Repro: repro-precommit-blob-read-cost-r1-size-header.sh (.out). Genuine git never pads, so this cannot happen on the real commit path" }
      - { rank: NON-BLOCKING, file: .aai/scripts/pre-commit-checks.sh, line: 103,
          issue: "NB-2: with only one free descriptor (RLIMIT_NOFILE 5, or fds 4..255 inherited), the EXIT trap's rm -rf cannot walk the scratch dir. The 0700 dir stays in TMPDIR with batch holding every staged blob, the detected secret included. D5's claim that every exit path removes it is false at that limit",
          failure_scenario: "ulimit -n 5; stage b.txt holding the api_key line; run the script: blocked (size mismatch), and the aai-pre-commit.* dir remains with the secret in batch (reproduced here)" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0301-spec-precommit-blob-read-cost.md, line: 193,
          issue: "NB-3 (validator's): D8(g) says the script gives the same result as 03f3e6df at 8 or more descriptors. That holds for the exit code only: at about 12-14 descriptors Node in CHECKs 8/9 hits EMFILE one limit earlier and adds a warning",
          failure_scenario: "ulimit -n 13: 03f3e6df prints PASS WITH WARNINGS: 2, new prints 3, both exit 0 (validator r4-later-checks-fd-probe.out). With --strict both block" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-pre-commit-checks.sh, line: 0,
          issue: "NB-4 (validator's): no test pins the NUL-count check (:143-145), the copy-count check (:190) or the four-space shape check (:118)",
          failure_scenario: "a later edit deletes any one of those lines and the whole suite stays green (validator r4 mutants)" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0301-spec-precommit-blob-read-cost.md, line: 106,
          issue: "NB-5 (validator's): D3 says any further byte after the last response fails closed. A trailing NUL is accepted, because bash read drops NULs",
          failure_scenario: "a wrapper appends one NUL after the batch output: no unrequested trailing output. Every content byte was still scanned, so this is a wording gap, not a fail-open" }
  cannot_verify:
    - { claim: "GNU/Linux (bash 5, GNU coreutils) behaviour of the new cases, notably TEST-3880 at ulimit -n 8/10 and with fds 10..254 held, and the bash read-then-dd offset handoff on fd 3", closes_with: "a green skill-suite CI run on Ubuntu for this head" }
    - { claim: "bash 5 abort scope for an arithmetic error inside a top-level if (the NB-1 class). Reproduced on /bin/bash 3.2.57 only", closes_with: "the NB-1 repro run under bash 5 on Linux" }
    - { claim: "behaviour at RLIMIT_NOFILE 4..7 under bash 5. Bash keeps its script fd at limit-1, which is fd 4 at limit 5, the fd exec 4< replaces. On bash 3.2 a toy script segfaulted there; the real script failed closed in the validator's sweep", closes_with: "a Linux fd sweep 4..7 with a staged secret" }
    - { claim: "Windows Git Bash (MSYS) dd, mktemp -d, read -u and descriptor behaviour (spec residual risk)", closes_with: "a Git Bash run of the suite" }
    - { claim: "wall-clock speed-up on 600 files (6.9 s vs 28 s) is a Planning and validator measurement; not re-measured here", closes_with: "the informational benchmark in the validation evidence" }
    - { claim: "EXIT-trap cleanup on SIGINT/SIGTERM during a commit. Untested; SIGKILL certainly leaves the scratch copies", closes_with: "a signal probe" }
  overall: pass
```

## Scope and method

- Worktree `/Users/ales/Projects/aai-worktrees/precommit-blob-read-cost`, branch `fix/precommit-batched-index-read`, base `03f3e6df`, uncommitted tree (STATE `worktree.user_decision: worktree`).
- Reviewed the whole `git diff 03f3e6df` for the five scope paths, not a delta.
  - `.aai/scripts/pre-commit-checks.sh`: +157/-18 against 03f3e6df (179/30 against the TEST-3454 base).
  - The suite: +459/-9.
  - CHANGELOG: +4.
  - The two untracked docs, read in full.
- Ledgers: `git diff 03f3e6df` on `docs/ai/EVENTS.jsonl` is +15/-0 and on `docs/ai/decisions.jsonl` +4/-0, so both are append-only.
- Run by me, on macOS with /bin/bash 3.2.57 and git 2.54.0:
  - `test-aai-pre-commit-checks.sh`: rc 0, 54 s, no SKIP-CASE.
  - `test-aai-docs-audit.sh`: rc 0.
  - `check-cd-subshell-leak.mjs`: rc 0.
  - `bash -n` on the script: OK.
  - `mutation-gate.mjs --spec …`: rc 5.
- My own probes (scratchpad, plus one repro beside this report):
  - the NB-1 repro;
  - the scope of an arithmetic-error abort;
  - `exec N<&-` under an exhausted table;
  - the scratch leftover at `ulimit -n 5`;
  - intent-to-add entries, which are identical to 03f3e6df because neither script lists them;
  - where bash keeps its script fd under low limits;
  - CI `fetch-depth: 0`, which TEST-3876 needs for its 03f3e6df baseline.

**Coaching disclosure.** The dispatch relayed the validator's NB list with its ratings and called NB-1 "wrapper-only". That pre-characterizes a finding. I reproduced NB-1 independently and rated every item myself. I also reviewed the full scope regardless.

## Spec compliance (AC walk)

All ten ACs are compliant (yaml block above). Every TEST-3871..3882 exists, is wired into `main()`, and passed in my suite run.

Deviations from the frozen spec:

1. **TEST-3880's declared mutation reference does not match its record (NB-0).**
   - The evidence exists in substance: the patch is byte-identical and the record says RED.
   - The deterministic gate still refuses, and `close-work-item.mjs` runs that gate.
   - The cell must be amended (additive-with-disclosure). A re-record cannot help, because `mutation-run` always writes the canonical name.
2. **Three spec sentences overstate the delivered behaviour:**
   - D5, "every exit path" (NB-2);
   - D8(g), "the same result" (NB-3);
   - D3, "any further byte" (NB-5).
   - None of these is a behavioural non-compliance with an AC row. They are false sentences in a record that is about to be signed at close.

I do not fail spec_compliance on NB-0. The H6 policy already makes it mandatory before closeout, and the close gate enforces it deterministically, so it cannot slip through.

## Code quality — my read

What is right, and was checked rather than assumed:

- **No builtin redirections in the parse.**
  - The list loop uses `exec 4<` and `read -u 4`.
  - The batch reader uses `exec 3<` and `read -u 3`.
  - `dd <&3` and `wc -c <` are external commands, so their redirections happen in the child.
  - That is the right fix at the cause for r3's B3.
- **Every numeric comparison has the form `[ x -eq y ] || staged_read_fail`.**
  - An empty or garbage value makes `[` return 2, which fails closed.
  - I saw this fire under `ulimit -n 5..7`: "cannot make pipe for command substitution" left `got=""`, and the run blocked with `size mismatch`.
- **The record split is correct for every `--raw` shape in use.**
  - It checks for exactly four spaces, then splits by parameter expansion.
  - `--no-renames` rules out score-bearing statuses.
- **The skip rules match the spec.**
  - D, U and mode 160000 are skipped.
  - The object id must be full-length, hexadecimal and not all zeros.
- **`printf | git cat-file --batch > file || fail`** has a builtin on the left, and `pipefail` covers both sides.
- **The EXIT trap is the only trap in the script**, so nothing later overrides it.
- **Scans read the copy through `< "$blob"`.**
  - The `grep -c` output is checked to be numeric, so a failed open cannot read as zero hits.
  - CHECK 3 (warning-only) has the readability test only, as D4 says.

Findings, each with my own severity:

### NB-0 — mutation reference mismatch (P2, record)

- Repro: `review-precommit-blob-read-cost-r1-mutation-gate.out` (gate rc 5).
- Not a code defect, but it hard-stops the close.
- **Disposition: (a) remediate in-tree before `/aai-pr`.**
  - Amend the TEST-3880 Mutation cell to `patch:docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3880.patch`, additive-with-disclosure, with a `spec_amendment` record.
  - The edit is text-only. Under standing decision 2026-09-12 (b), the validation and review verdicts stand and the staleness is disclosed in the notes.
  - Re-run `mutation-gate.mjs`; it must exit 0.

### NB-1 — arithmetic error discards the parse block (P3, assurance strength)

- Repro: `repro-precommit-blob-read-cost-r1-size-header.sh` / `.out`.
  - With a header size of `028`: exit 0, `PASS WITH WARNINGS`, the staged secret unreported. 03f3e6df blocks.
  - With a 20-digit size: blocked (`size mismatch`). So only the leading-zero form opens the hole.
- My standalone probe on bash 3.2 confirms the mechanism. An arithmetic expansion error drops the entire enclosing top-level command, and execution resumes after it with rc 0, even under `set -e`.
- **Why P3 and not BLOCKING:**
  - Genuine git prints sizes undecorated.
  - No real fault (truncation, disk full, signal) produces a zero-padded size.
  - A git that lies can already defeat any content guard, more simply, by serving clean bytes with consistent sizes.
  - So the path gives an attacker nothing new.
- **Why it still matters:**
  - It contradicts the intake's "a header that does not parse … blocks the commit; none of them may let the commit through unscanned".
  - It shows that the D13 cross-checks are not independent of the loop as claimed: they sit in the same top-level command and die with it. Any future expansion error in that block becomes a silent fail-open.
- **Remedy, about 4 lines plus a pin:**
  - Reject the leading zero: `case "$size" in ''|*[!0-9]*|0?*)`, or use `$((10#$size))`.
  - Set a sentinel `PCC_PARSED=1` as the block's last statement.
  - Check it in a SEPARATE top-level command: `[ "$PCC_LIST" -eq 0 ] || [ "${PCC_PARSED:-0}" -eq 1 ] || staged_read_fail "…"`.
  - That closes the whole class, not only `08`.
- **Recommended disposition: (b) follow-up `suggested: fu-precommit-parse-discard-sentinel`, P3.**
  - This ride has already used its one extension (`round-budget`: 3/3, extensions 1).
  - A code fix changes executable bytes and needs re-validation, which is a second extension and therefore a STOP that asks the owner.
  - Alternative: fold it into this ride if the owner grants that extension.

### NB-2 — scratch dir left at RLIMIT_NOFILE ≤ 5 (P3)

- Reproduced here. At `ulimit -n 5` the run blocks, but `aai-pre-commit.*/batch` holding the api_key line stays in TMPDIR (6 files).
- Exposure: the copy sits in a same-user 0700 directory, and the same bytes are already in `.git/objects`. Exposure is not widened beyond the owner.
- My probe shows a cheap fix. On bash 3.2, `exec 3<&- 4<&-` does close both descriptors under an exhausted table, even though it prints "cannot duplicate fd". A following `rm -rf` then succeeds. So the trap could close 3 and 4, with stderr silenced, before `rm`.
- **Disposition:**
  - (a) qualify D5's "every exit path" in the same text-only amendment as NB-0.
  - Plus (b) `suggested: fu-precommit-scratch-left-at-low-nofile`, P3, for the trap change.
  - (d) is not available here, because D5 as written is a false record.

### NB-3 — D8(g) overclaims (P3, text)

- **Disposition: (a)** in the NB-0 amendment: "the same exit code; at about 12-14 descriptors, CHECKs 8/9 may print one more warning".

### NB-4 — NUL-count, copy-count and four-space checks unpinned (P3)

- **Disposition: (b)**, folded into the NB-1 follow-up. A sentinel fix needs a pin anyway, and the same follow-up can add one case per cross-check.

### NB-5 — trailing NUL not detected (P3, text)

- **Disposition: (a)** in the NB-0 amendment: "any further non-NUL byte", or disclose it.

### NB-6 (validator's) — stale `first_fail` prose in `mutation-TEST-3877.txt` (P3)

- The record still reddens on replay. The message is the test's own unmutated text, not a false claim.
- accepted residual: the first_fail line of mutation-TEST-3877.txt echoes the suite's unmutated pin text; the record's RED verdict and replay are correct, so no false record remains.

### INFO (no failure mode that gates)

- **Size.** The script gained 157 lines and lost 18, and is now 472 lines. For a perf fix, that much fail-closed bash is a lot of surface. The header comment is accurate, though, and the code is linear.
- **Two non-git processes per staged file remain** (`dd`, `wc`), as disclosed.
- **Staged content is now copied to TMPDIR** (0700) for the run's duration. That is a new at-rest copy, removed on every normal exit.
- **CHECK 3 (warning-only)** silently loses its scan if the copy vanishes between the `-r` test and the redirect. That matters only with `--strict`, and D4 discloses it.
- **Test robustness.**
  - The wrappers use only `head -c`, `sed '$d'`, `tr` and `tail -n +2`, which are portable on GNU and BSD.
  - The fd-hold loop sets the 256 limit explicitly, so it does not depend on Linux's higher default.
  - The TEST-3882 grep shim is deterministic, because CHECK 2's first grep runs after the parse.
  - `ulimit -f 200` relies on SIGXFSZ, which is portable.
  - Nothing in them is timing-sensitive, so I see no CI-load flake risk.

## Warning dispositions (H6)

| WARNING | Severity | Disposition |
|---|---|---|
| NB-0 | P2 | (a) remediate before /aai-pr: text-only amendment of the TEST-3880 cell, then mutation-gate rc 0 |
| NB-1 | P3 | (b) `suggested: fu-precommit-parse-discard-sentinel` (or fold in on an owner-granted second extension) |
| NB-2 | P3 | (a) qualify D5 in the NB-0 amendment, plus (b) `suggested: fu-precommit-scratch-left-at-low-nofile` |
| NB-3 | P3 | (a) qualify D8(g) in the NB-0 amendment |
| NB-4 | P3 | (b) folded into `fu-precommit-parse-discard-sentinel` |
| NB-5 | P3 | (a) qualify D3 in the NB-0 amendment |
| NB-6 | P3 | (d) accepted residual (quoted above) |

## Next steps

1. Orchestrator makes one text-only spec amendment covering NB-0, NB-2, NB-3 and NB-5, with a `spec_amendment` record. It then re-runs `mutation-gate.mjs` (rc 0 expected) and `spec-amend list --strict`.
2. File follow-ups for NB-1 (with NB-4) and NB-2.
3. Run `/aai-pr`. CI on Ubuntu closes the GNU/bash 5 cannot-verify items.
