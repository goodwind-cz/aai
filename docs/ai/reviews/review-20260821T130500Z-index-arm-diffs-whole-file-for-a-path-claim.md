# Code Review — index-arm-diffs-whole-file-for-a-path-claim

```yaml
review:
  scope: 94ee37d..38d3e5a (branch fix/index-arm-path-claim) — tests/skills/test-aai-docs-audit.sh (+460/-16)
  spec: docs/specs/SPEC-0141-spec-index-arm-diffs-whole-file-for-a-path-claim.md
  ceremony_level: 1
  reviewer_model: claude-opus-5 (adversarial code-review role, read-only on implementation files)
  prior_evidence: docs/ai/validation/validation-20260821T123200Z-index-arm-diffs-whole-file-for-a-path-claim-round1.md (PASS, round 1) — read first, not repeated
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-docs-audit.sh:2177-2231 — pinned-clock pair, self-verifying via the day_earlier != day_fresh guard at :2187" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-docs-audit.sh:2239-2276 — bite (:2261) + unmutated control (:2273) + zero-token vacuity guard (.mjs :1992)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "tests/skills/test-aai-docs-audit.sh:2278-2326 — separately named arm, both bites, 'STALE' asserted at :2301" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "tests/skills/test-aai-docs-audit.sh:2329-2400 — observed 0 -> 1 heading move at :2371-2374, masked diff 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 2077,
          issue: "the D6 restore floor is armed too late — test_spec0006_no_regression_real_repo regenerates the real docs/INDEX.md twice while INDEX_REAL_BACKUP is still empty",
          failure_scenario: "Ctrl-C or a CI timeout during that arm's two generator runs leaves tracked docs/INDEX.md dirty; cleanup() is a no-op there because INDEX_REAL_BACKUP == ''" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 1956,
          issue: "index_posix_findings overloads exit 1 for 'the index has a bad path' and 'the predicate could not run'; stderr is not folded into the captured output",
          failure_scenario: "docs-model.mjs fails to import -> node exits 1 with empty stdout -> the arm prints 'FAIL: committed docs/INDEX.md must carry forward-slash paths only:' with nothing after the colon (reproduced)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 2077,
          issue: "INDEX_REAL_BACKUP is assigned BEFORE the cp that fills it, and cleanup()'s restore is silenced by '|| true'",
          failure_scenario: "a cp that fails partway (ENOSPC on $TMPDIR) leaves a truncated but existing backup; the EXIT trap then overwrites the tracked index with it and says nothing" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 1898,
          issue: "index_strip_dated clears in_overdue only on /^## /, so the Overdue mask runs to EOF if that section ever stops being followed by a level-2 heading",
          failure_scenario: "a generator change that emits Overdue last (or a '# '/'---' footer after it) masks the rest of the file; masked diff 0 = green, and kept_lines > 20 is far too loose on a 431-line index" }
  cannot_verify:
    - { claim: "the four arms pass on a GNU/Linux CI runner (BSD vs GNU diff/awk/sed/grep -o)",
        closes_with: "the ci-full labelled PR run already required as validation obligation O1" }
    - { claim: "index_strip_dated stays exhaustive against FUTURE generator changes",
        closes_with: "a generator-side assertion, or deriving the mask from the generator instead of enumerating it" }
    - { claim: "the EXIT trap fires on SIGINT/SIGTERM under the CI runner's bash",
        closes_with: "validation proved it on bash 3.2 locally; a CI-side repeat would close it" }
  overall: pass
```

## Scope and method

Diff established from the named refs myself (`git diff 94ee37d 38d3e5a`), not from a pasted
diff. `git status --porcelain` was empty at start. The change is one file plus its spec/issue/
telemetry companions; only `tests/skills/test-aai-docs-audit.sh` carries logic.

Validation round 1 re-derived every number, reran every bite proof, ran the pre-change baseline
end to end, and defeated nothing. I did not repeat it. What I did instead:

- read all 460 new lines against this repo's specific shell-injury history (`rc=$?` after a pipe,
  `grep | head` SIGPIPE, unquoted expansion, `log_fail` trapped in a subshell, a `sed` anchor that
  restores nothing);
- executed `index_stale_findings` against the real index under `/bin/bash -c 'set -euo pipefail'`
  by sourcing the shipped suite (bash 3.2.57, the local interpreter) — rc 0,
  `tracked_checked=371 index_paths_checked=371`;
- executed it again against a hand-built `Source: docs/{}/**/*.md` index to drive the empty-array
  path under `set -u` on bash 3.2 (the version where `declare -a x=()` quirks live) — rc 1,
  `STALE-CHECK ABORTED: the Source line named no directory`, no unbound-variable crash;
- extracted the shipped Node predicate verbatim and ran it with a broken lib import to test the
  failure-message claim (finding 2, reproduced);
- read `.aai/scripts/generate-docs-index.mjs` for every write target and for section order.

I did not re-run the 5-minute suite. Validation ran it four times against this exact code and the
diff has not moved since; a fifth run is a re-verification, which is precisely what this pass was
told not to spend its budget on. Everything I assert below was either read as code or executed as
an isolated fragment, and each is cited.

## Verdict 1 — spec_compliance: pass

| Spec-AC | Call | Citation and what I checked, beyond validation's re-derivation |
|---|---|---|
| Spec-AC-01 | compliant | `:2177-2231`. I judged the construction, not the numbers. The pinned clock is honest: the loader swaps `globalThis.Date` before `await import`, so the generator's module-scope `const today = new Date()` (`generate-docs-index.mjs:59`) is already pinned, and `Date.UTC`/`Date.parse` come through class static inheritance unchanged. More importantly it **cannot fail silently**: `:2187` asserts the two `Today (UTC):` lines actually differ and calls the vacuity out by name. If the generator moved its clock read to `Date.now()`, `FakeDate.now()` still pins it; if it moved to something the swap cannot reach, that guard reddens loudly rather than the arm passing on an unmoved pair. That is the property that makes this construction safe to depend on. |
| Spec-AC-02 | compliant | `:2239-2276`. The AC asks that a backslash separator fail the arm with a message naming the path problem; it does (`not POSIX`, asserted at `:2264`), with a `cmp -s` guard at `:2257` proving the mutation was not a no-op and an unmutated control at `:2273`. Finding 2 concerns a *different* trigger (the predicate failing to run) and does not touch this AC. |
| Spec-AC-03 | compliant | `:2278-2326`. Separately named arm, both directions bite, the finding text is asserted to contain `STALE` and to name the document. Carries the two already-filed caveats (`fu-staleness-source-line-self-certifies`, `fu-stale-arm-reads-worktree-index`) — I concur with both; neither breaks the AC as written. |
| Spec-AC-04 | compliant | `:2329-2400`. The fixture's Review-By is derived from a single anchor (`:2333-2335`), and I checked the straddle algebra: `earlier = anchor-3d < past = anchor-1d < real now` holds even if UTC midnight crosses mid-arm, in both directions. The heading move is *observed* (`:2371`, `:2373`), not argued. |

Implementation-plan item **D6 is only partially delivered** (finding 1). D6 is a design decision, not
a Spec-AC, and no AC row asserts it, so it does not sink this verdict — but the spec text says the
trap covers "the real-repo arms" and the shipped comment says "on EVERY exit path", and one real-repo
arm is outside it. Recording that as a code_quality finding rather than a compliance failure is the
honest placement; recording it as neither would not be.

Test Plan rows TEST-001..004 all exist at the paths claimed and all four ran green in validation's
two post-change suite runs (151 PASS / 0 FAIL).

## Verdict 2 — code_quality: pass, with four NON-BLOCKING findings

### Finding 1 (P2) — the restore floor is armed after the first real-repo regeneration

`tests/skills/test-aai-docs-audit.sh:25` (`INDEX_REAL_BACKUP=""`), `:35-37` (the trap's restore),
`:2077-2078` (where it is finally set), `main()` at `:5945-5951`.

`setup_indexarm_snapshots` is called from `main()` **after** `test_spec0006_no_regression_real_repo`
(`:1835-1861`), and that arm regenerates the real `docs/INDEX.md` twice (`:1851`, `:1854`) with only
its own local `$TEST_DIR/INDEX.md.orig` as protection. Throughout that window `INDEX_REAL_BACKUP` is
still `""`, so the new `cleanup()` restore is a no-op.

Failure scenario, and it is the ordinary one: press Ctrl-C during those two generator runs — a
five-minute suite invites exactly that — or let a CI step timeout send SIGTERM, and a tracked
`docs/INDEX.md` is left dirty with a fresh `Generated:` stamp and no explanation. That is the same
symptom D6 was written to end, reproduced inside the change that claims to end it. The arm's own
`|| { cp "$idx_backup" "$idx"; log_fail ... }` covers a *node failure*; it cannot cover a signal.

This is not a regression — pre-change the whole suite was unprotected — so it is an incomplete fix
plus an overclaiming comment, not new damage, and the dirty file is recoverable. That is why it is
NON-BLOCKING rather than BLOCKING. The fix is two lines: take the backup in `setup_fixture()` (where
`TEST_DIR` already exists) instead of in `setup_indexarm_snapshots`, and let both arms read it.

Filed as `fu-index-floor-armed-after-first-regen`.

### Finding 2 (P2) — the POSIX predicate reports an infrastructure failure as a path defect, with an empty message

`tests/skills/test-aai-docs-audit.sh:1956-1960` (the helper), `:1962-2007` (the Node predicate),
call sites `:2246`, `:2250`, `:2214`, `:2392`.

The predicate exits 1 for findings. It also exits 1 for every way it can fail to run: the
`await import` of `docs-model.mjs` throwing, an unreadable index, the predicate file itself missing.
`index_posix_findings` does not fold stderr into stdout, and the call sites capture stdout only —
so on an infrastructure failure `$out` is empty and the arm prints:

```
FAIL: committed docs/INDEX.md must carry forward-slash paths only:
```

Reproduced, not argued: running the shipped predicate verbatim against the real index with a
nonexistent lib path gives `rc=1` and `captured-stdout=[]`. The node stack does reach the terminal
on stderr, so an operator reading the whole log can recover — but the FAIL line, which is what CI
summaries and the eye land on, names the wrong thing with nothing after the colon. This is the exact
defect class the ride was chartered to eliminate, surviving inside the replacement.

The author half-saw it: the `toPosix is not exported` case at `:1966-1969` prints an explanation —
but routes it through the same exit 1, so it still arrives as "the index has a bad path". Note the
shell sibling got this right: `index_stale_findings` emits `STALE-CHECK ABORTED: …` with distinct
wording for every non-judgement outcome (`:2015`, `:2025`, `:2032`). The asymmetry is the finding.

Fix: exit 2 for "cannot run", have `index_posix_findings` capture `2>&1`, and branch the arms on
rc 2 with a message that says the predicate could not run.

Filed as `fu-posix-predicate-exit-conflates-infra`.

### Finding 3 (P3) — the floor can write a truncated backup over the tracked index, silently

`tests/skills/test-aai-docs-audit.sh:2077-2078` and `:35-37`.

```
INDEX_REAL_BACKUP="$TEST_DIR/INDEX.real.orig"
cp "$idx" "$INDEX_REAL_BACKUP"
```

The pointer is published before the copy that fills it, and `cleanup()` gates only on `-f`. If that
`cp` fails partway — ENOSPC on `$TMPDIR` is the realistic one on a shared CI box — errexit fires, the
EXIT trap finds a truncated-but-existing backup, and copies it over the tracked `docs/INDEX.md`. The
`|| true` at `:36` then swallows the only signal, so a failed *or* wrong restore produces no output at
all. That silence is also a `.aai/AGENTS.md` "degrade-with-NOTE" violation: any step that degrades
must name it.

Same `|| true` covers the ordinary case worth naming: the floor now holds a five-minute-wide window
in which anything else that writes `docs/INDEX.md` (a pre-commit hook regeneration in another
terminal) is reverted at exit without a word. Pre-change that window was two spans of a few seconds.

Fix: `cp "$idx" "$tmp" && INDEX_REAL_BACKUP="$tmp"`, and replace `|| true` with a warning on stderr.

Filed as `fu-index-floor-silent-partial-restore`.

### Finding 4 (P3) — the mask's section terminator can run away, and the comment claims it cannot

`tests/skills/test-aai-docs-audit.sh:1898-1906`.

```awk
/^## / { in_overdue = (index($0, "## Overdue reviews (") == 1) }
in_overdue { next }
```

`in_overdue` is cleared **only** by a level-2 heading. Today that is safe by luck of ordering:
`generate-docs-index.mjs:426` emits `Overdue reviews` as the *first* section and
`## Active (implementing)` follows immediately, which is why validation measured exactly 6 masked
lines out of 431. But the shipped comment at `:1891-1893` claims the helper can only ever
*under*-mask ("the safe direction"), and that is true only for a *new* dated surface. If the Overdue
section is ever emitted last, or a `# ` heading or a non-`##` footer follows it, the mask eats
everything to EOF — and the failure direction is silent: masked diff 0 reads as green. The only
guard is `kept_lines > 20` at `:2203`, which a 431-line index clears while retaining 21 lines, and
TEST-004 has no such guard at all (already filed as `fu-test004-missing-mask-vacuity-guard`).

On the design question the dispatch asked: an enumerated mask *is* the wrong shape in principle —
it is a hand-maintained copy of the generator's date coupling with nothing keeping the two in sync —
but it is the right shape *here*, because the failure mode of an enumeration is a red arm showing
the unmasked line, which is diagnosable, whereas a pattern mask ("any line with a date") fails
green. The enumeration is defensible. Its terminator is not.

Fix: terminate on `/^#/` rather than `/^## /`, and make the vacuity guard a fraction of the input
line count rather than the constant 20.

Filed as `fu-strip-dated-runaway-section-mask`.

## What I attacked and could not break

Named so this pass is falsifiable rather than merely negative.

- **Failure propagation out of subshells, pipelines and command substitutions.** Every `log_fail` in
  the new code is at function top level, called directly from `main()`, which runs unguarded at
  `:5985`. None is inside `$( )`, a pipeline, or a `( )` group. The `$(cat …)` interpolations inside
  `log_fail` arguments are arguments, not the call. `log_fail` is `exit 1`, and the four new arms
  reach `main()` directly. Could not construct a swallowed failure.
- **`rc=$?` after a pipe.** Every rc capture in the new code is `out="$(fn …)" || rc=$?` on a plain
  command substitution — no pipes. `rc=0` is re-established before every single capture (`:2242`,
  `:2249`, `:2260`, `:2266`, `:2213`, `:2216`, `:2282`, `:2293`, `:2307`, `:2317`, `:2390`, `:2392`).
  Checked all twelve.
- **`diff` under `pipefail`.** All four raw/masked/proxy counts use `"$( { diff a b || true; } | wc -l | tr -d ' ' )"` — the brace group neutralises diff's rc 1 *before* the pipe, which is the correct
  form and is used consistently. Could not find the naive `diff | wc -l`.
- **`printf | grep -q` / `extract_section | grep -q` SIGPIPE under `pipefail`.** Five new
  occurrences (`:2268`, `:2301`, `:2303`, `:2315`, `:2376`). This is the house pattern — 40+
  pre-existing occurrences including `extract_section … | grep -qF` at `:843`, `:882`, `:2440` — the
  payloads are a handful of lines that fit the pipe buffer before `grep -q` exits, and the suite has
  never flaked on it. Not a regression and not a live defect; noted, not filed.
- **bash 3.2 array/`set -u` traps.** `local -a pathspec=()` followed by `${#pathspec[@]}` is the
  classic bash-3.2 unbound-variable trap; I executed both the length probe and the real function on
  the empty-`Source` path under `/bin/bash -c 'set -euo pipefail'` on 3.2.57. Clean, and the guard
  at `:2027` returns before `"${pathspec[@]}"` is ever expanded empty. Could not break it.
- **`IFS` handling.** `IFS=','` is saved and restored around the split loop (`:2019`, `:2026`), and
  the later `while IFS= read -r` loops scope their own. The unquoted `$dirs` split is deliberate and
  runs under bash, not zsh. Correct.
- **Tracked side effects beyond `docs/INDEX.md`.** Read every write in the generator:
  `INDEX.md` (`:582`), `INDEX.violations.md` (`:137`, removed at `:85` when clean),
  `INDEX.audit.md` (`:153`, gitignored at `.gitignore:75`). `runAudit` comes from the pure
  `lib/docs-audit-core.mjs`, not the CLI, so no `EVENTS.jsonl` append — the pinned-clock run does
  **not** write fake-dated telemetry into tracked append-only data, which was my main worry about
  running a clock-swapped generator against the real repository. The floor covers the only tracked
  file the suite writes. Also checked the ordering: the earlier-day run writes a fake-dated
  `INDEX.audit.md` and the fresh run overwrites it, so the developer's sidecar is left correct — but
  that correctness depends on an undocumented ordering inside `setup_indexarm_snapshots` (`:2088`
  before `:2090`).
- **`cleanup()` re-entrancy and ordering.** Restore sits above the `KEEP_TEST_DIR` early return and
  above the `rm -rf` that would delete the backup — both required, both correct, and both stated in
  the comment. Running twice is idempotent (`cp` of the same bytes; after `rm -rf` the `-f` guard
  makes it a no-op). An early `log_fail` before the backup exists (`:2076`) leaves
  `INDEX_REAL_BACKUP` empty, so the trap correctly does nothing — nothing was modified at that point.
  The only ordering defect is finding 1, which is *outside* `cleanup()`.
- **The `sed` mutation.** `sed 's#docs/specs/#docs\\specs\\#'` inside single quotes yields literal
  `docs\specs\`, and `:2257` proves with `cmp -s` that it changed something — the "anchor matched
  nothing and silently restored nothing" trap is explicitly closed. Could not make it vacuous.
- **`utc_day` argv handling.** `node -e '…' -- "$1" "$2"` with a negative offset: verified
  empirically that `process.argv[1]`/`[2]` land on the anchor and the offset and that `-3` is not
  eaten as a node flag.
- **Midnight straddle in both arms.** One anchor per arm, every offset derived from it; I worked the
  inequalities for both `setup_indexarm_snapshots` and TEST-004 and both hold across a crossing.
- **Message quality.** Graded all 31 new `log_fail` messages. They are, with two exceptions, the best
  in this file: every masked-diff failure inlines the actual diff (`:2206`, `:2386`), every bite
  proof states which mutation failed to bite and carries an unmutated control, and every vacuity
  guard says the word "vacuous" and which check would have been vacuous. The exceptions are finding 2
  and `:2355` `log_fail "iso-repo fixture commit failed"`, which covers both `git add -A` and
  `git commit` and carries no git output (stderr leaks to the terminal, not into the message) — too
  minor to file.

## Duplication and drift

- The POSIX and staleness predicates are executed five times across four arms (`:2214`, `:2217`,
  `:2246`, `:2250`, `:2282`, `:2390-2393`). That is not redundancy: AC-001 and AC-004 assert that
  those properties *survive the date boundary*, which is the whole point, and every call site's
  message names which snapshot it was judging. Correct as written.
- TEST-001 and TEST-004 do share one shape — generate at two dates, assert raw diff > 0, mask, assert
  masked diff 0 — duplicated rather than extracted. The concrete cost of not extracting it is the
  already-filed `fu-test004-missing-mask-vacuity-guard`: TEST-004 is missing the `kept_lines` guard
  its twin has. I concur with that filing and add the shape: the fix is one shared
  `assert_only_dated_surfaces_differ <a> <b>` helper, not a second copy of the guard.
- **TEST-id collision inside one file** (INFO, not filed). Four functions now carry `TEST-001` in
  their comments, three carry `TEST-003`, two carry `TEST-004`, drawn from two different specs; the
  narrowed arm's header reads `TEST-003 / TEST-002`. `check-test-registration.mjs` passes because ids
  are spec-scoped, and D7's reason for keeping the function name is sound. But a reader grepping
  `TEST-003` in this file now gets three hits pointing at two different claims. Worth a
  `<spec-slug> TEST-00n` prefix in the comments next time this file is touched.
- **Naming** (INFO, not filed). `test_indexarm_index_is_not_stale` names the property — good, and it
  is the arm whose failure text most clearly says what broke. `..._earlier_day_generation_is_green`
  and `..._overdue_boundary_is_green` name the expected *outcome* rather than the property; they
  would read better as `..._differs_only_in_dated_surfaces` and `..._overdue_move_changes_nothing_else`.
  I considered `is_not_stale` against the prompt's BLOCKING rule for names claiming a universal
  negative over a subset of paths — row metadata, headings, counts and ordering are genuinely
  unasserted (`fu-index-row-metadata-unasserted`). I judge it **not** BLOCKING: "stale" is defined
  operationally by `index_stale_findings` in the same file, the arm's `log_info` states the exact
  claim ("lists every tracked doc and no deleted one"), and the residual gap is already filed and
  visible. A rename would still be an improvement.
- `setup_indexarm_snapshots` emits a `log_pass` (`:2100`) although it is setup, not an arm — this is
  the fourth of the 147 -> 151 arm-count delta. Harmless, matches `setup_spec0006_opendecision_fixture`
  precedent in the same `main()`.

## Concurrence with the five already-filed findings

I found all five independently and do not refile them. Two get a cheaper fix than the one recorded:

- `fu-staleness-source-line-self-certifies` (P2) — concur. Cheaper fix than "derive from
  `FAMILY_DIR_NAMES`": the generator emits that line from the same registry at
  `generate-docs-index.mjs:414`, so the arm can simply assert the index's `Source:` line equals the
  one a fresh generation emits — one comparison, no duplicated registry.
- `fu-posix-arm-reddens-on-prose-backslash` (P2) — concur. The fix is smaller than it looks: the
  `matchAll` loop on the very next line (`:1983`) already extracts path-shaped tokens, and its
  character class already admits `\\`. Moving the `line.includes('\\')` test inside that loop and
  reporting on `tok` fixes it in two lines without weakening the check.
- `fu-test004-missing-mask-vacuity-guard` (P3) — concur; see Duplication above.
- `fu-index-row-metadata-unasserted` (P3) — concur; this is the real cost of the AC-003
  reformulation and it is correctly named as such.
- `fu-stale-arm-reads-worktree-index` (P3) — concur.

## Verdict 3 — cannot_verify

1. **Cross-platform behaviour on a GNU/Linux CI runner.** Everything I executed ran on macOS/BSD with
   bash 3.2. `sed`, `grep -oE`, `awk` and `diff` usages all look portable and the arms only compare
   diff output against 0 / >0 rather than against exact line counts, but I cannot substantiate a GNU
   pass from the diff. Closes with the `ci-full` PR run that validation already recorded as
   obligation O1.
2. **Mask exhaustiveness against future generator changes.** Validation proved it against today's
   generator at eight pinned dates; nothing keeps the enumeration in sync tomorrow. Closes with a
   generator-side assertion or a derived mask. Finding 4 is the near-term half of this.
3. **EXIT-trap delivery on SIGINT/SIGTERM under the CI runner's shell.** Proven locally by
   validation on bash 3.2; unproven on the runner. Closes with a CI-side repeat.
4. **The five-minute suite itself.** Deliberately not re-run here — validation ran it four times
   against this exact code (151 PASS / 0 FAIL twice post-change; 147 PASS pre-change baseline) and a
   fifth run is a re-verification, not a review. Stated so it is a named gap rather than a silent one.

## Overall: pass

I would merge this as is. It is a careful, unusually well-instrumented change: every new assertion
carries a vacuity guard, every bite proof carries an unmutated control, the pinned-clock construction
is self-verifying rather than merely clever, and the retired proxy is pinned as an executable negative
so the defect cannot come back quietly. The four findings are all NON-BLOCKING — one incomplete
safety floor whose uncovered window predates this change, one misattributed failure message that
requires an independent infrastructure failure to appear, and two hardening items — and none of them
is a defect the shipped arms will hit on a normal run.

The two findings I would most want fixed before this file is touched again are finding 1 (two lines,
and it completes the guarantee D6 already claims in the comment) and finding 2 (it is the ride's own
defect class, surviving inside the fix).

## Warning dispositions (H6)

All four NON-BLOCKING findings are promoted to typed follow-ups in `docs/ai/decisions.jsonl` via
`node .aai/scripts/follow-ups.mjs add`, each read back from the ledger after filing:

| Finding | Severity | Follow-up id | Disposition |
|---|---|---|---|
| 1 — floor armed after first regen | P2 | `fu-index-floor-armed-after-first-regen` | promote-to-follow-up |
| 2 — POSIX predicate exit conflates infra | P2 | `fu-posix-predicate-exit-conflates-infra` | promote-to-follow-up |
| 3 — silent/partial restore | P3 | `fu-index-floor-silent-partial-restore` | promote-to-follow-up |
| 4 — runaway section mask | P3 | `fu-strip-dated-runaway-section-mask` | promote-to-follow-up |

INFO notes (TEST-id collision, two arm names, `iso-repo fixture commit failed` message) are recorded
in this report only and do not gate.

## Next steps

1. Flip the four Spec-AC rows to a terminal status at the close ceremony, before `close-work-item.mjs`
   — the `--gate` / false-open catch-22 is the precedented one validation measured.
2. Carry the `ci-full` label on the PR (validation obligation O1), which also closes cannot_verify 1.
3. Stage this report with the scope's commit per the report-staging rule.
